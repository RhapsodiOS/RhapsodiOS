#import "TerminalDO.h"

#import <Foundation/NSData.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSConnection.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSString.h>
#import <Foundation/NSPort.h>
#import <Foundation/NSPortNameServer.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>

#import "Emulation.h"
#import "ProcessIdentity.h"
#import "Shell.h"
#import "ShellExec.h"
#import "ServiceProvider.h"
#import "Terminal.h"
#import "TerminalApp.h"

#include <fcntl.h>
#include <mach/mach_init.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/select.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;
extern id _theDefaultsObject;
extern kern_return_t bootstrap_register(port_t bootstrapPort,
    char *serviceName, port_t servicePort);

@interface DirtMonitor
- (BOOL)isDeviceDirty:(int)device;
@end

static int nextWindowHandle;

static NSData *environmentDataFromDictionary(NSDictionary *environment,
    unsigned int capacity)
{
    NSMutableData *data;
    NSEnumerator *keys;
    NSString *key;
    unsigned char equalsSign;
    unsigned char zero;
    NSStringEncoding encoding;

    data = [[NSMutableData dataWithCapacity:capacity]
        mutableCopyWithZone:(NSZone *)capacity];
    keys = [environment keyEnumerator];
    encoding = [NSString defaultCStringEncoding];
    equalsSign = '=';
    zero = 0;
    while ((key = [keys nextObject]) != nil) {
        NSData *keyData = [key dataUsingEncoding:encoding
            allowLossyConversion:YES];
        NSData *valueData = [[environment objectForKey:key]
            dataUsingEncoding:encoding allowLossyConversion:YES];

        [data appendData:keyData];
        [data appendBytes:&equalsSign length:1];
        [data appendData:valueData];
        [data appendBytes:&zero length:1];
    }
    if ([data length] <= 2) {
        [data release];
        return nil;
    }
    [data appendBytes:&zero length:1];
    return [data autorelease];
}

char **environmentFrom(NSData *data, NSZone *zone)
{
    unsigned int length = [data length];
    const unsigned char *bytes = [data bytes];
    unsigned int nulCount = 0;
    unsigned int trailingNuls = 0;
    unsigned int index;
    unsigned int i;
    char **environment;

    for (index = 0; index < length && trailingNuls <= 1; ++index) {
        if (bytes[index] == 0) {
            ++trailingNuls;
            ++nulCount;
        } else {
            trailingNuls = 0;
        }
    }
    if (trailingNuls <= 1)
        return NULL;

    if (zone == nil)
        zone = NSDefaultMallocZone();
    environment = (char **)NSZoneMalloc(zone,
        (unsigned int)(sizeof(char *) * nulCount));
    if (environment == nil)
        return NULL;

    bytes = [data bytes];
    for (i = 0; i < nulCount - 1; ++i) {
        environment[i] = (char *)bytes;
        while (*bytes++ != 0)
            ;
    }
    environment[i] = NULL;
    return environment;
}

@implementation TerminalDO

- (id)init
{
    NSConnection *connection;
    NSPort *receivePort;

    if (nextWindowHandle != 0)
        return self;

    [super init];

    srandom((unsigned int)time(NULL));
    nextWindowHandle = (unsigned short)random() + 1;

    connection = [NSConnection defaultConnection];
    [connection setRootObject:self];
    receivePort = [connection receivePort];
    if (bootstrap_register(bootstrap_port, "TerminalDO",
            (port_t)[receivePort machPort]) != 0) {
        [self release];
        return nil;
    }

    if ([[NSPortNameServer defaultPortNameServer]
            portForName:@"PublicDOServices"] != nil)
        [connection registerName:@"TerminalDO"];

    return self;
}

- (int)protocolVersion
{
    return 65538;
}

- (void)runCommand:(NSString *)command windowTitle:(NSString *)windowTitle
{
    int handleAndReturnCode;

    [self runCommand:command inputData:nil outputData:NULL errorData:NULL
        waitForReturn:NO windowType:TSWindowNew
        windowHandle:&handleAndReturnCode exitAction:TSCloseUnlessError
        shellType:TSShellFastC windowTitle:windowTitle directory:nil
        environment:nil returnCode:&handleAndReturnCode];
}

- (void)runCommand:(NSString *)command windowType:(TSWindowType)windowType
    windowHandle:(inout int *)windowHandle shellType:(TSShellType)shellType
    windowTitle:(NSString *)windowTitle returnCode:(out int *)returnCode
{
    [self runCommand:command inputData:nil outputData:NULL errorData:NULL
        waitForReturn:NO windowType:windowType windowHandle:windowHandle
        exitAction:TSCloseUnlessError shellType:shellType
        windowTitle:windowTitle directory:nil environment:nil
        returnCode:returnCode];
}

- (void)runCommand:(NSString *)command inputData:(NSData *)inputData
    outputData:(NSData **)outputData waitForReturn:(BOOL)waitForReturn
    directory:(NSString *)directory returnCode:(out int *)returnCode
{
    int windowHandle;
    [self runCommand:command inputData:inputData outputData:outputData
        errorData:NULL waitForReturn:waitForReturn windowType:TSWindowNone
        windowHandle:&windowHandle exitAction:TSCloseUnlessError
        shellType:TSShellFastC windowTitle:nil directory:directory
        environment:nil returnCode:returnCode];
}

- (void)runCommand:(NSString *)command inputData:(NSData *)inputData
    outputData:(NSData **)outputData errorData:(NSData **)errorData
    waitForReturn:(BOOL)waitForReturn windowType:(TSWindowType)windowType
    windowHandle:(inout int *)windowHandle exitAction:(TSExitAction)exitAction
    shellType:(TSShellType)shellType windowTitle:(NSString *)windowTitle
    directory:(NSString *)directory environment:(NSDictionary *)environment
    returnCode:(out int *)returnCode
{
    TerminalApp *application = (TerminalApp *)NSApp;
    ServiceProvider *serviceProvider =
        (ServiceProvider *)[application serviceProvider];
    NSString *commandString = command != nil ? command : @"";
    const char *commandBytes = [commandString cString];
    const char *directoryBytes = [directory cString];
    NSData *environmentData = environmentDataFromDictionary(environment, 0);
    Terminal *terminal = nil;
    NSArray *windows;
    unsigned int windowIndex;
    int resultCode = 0;
    int outputPipe[2];
    int errorPipe[2];
    pid_t child;
    int status;
    unsigned int pollCount;
    NSMutableData *outputBuffer = nil;
    NSMutableData *errorBuffer = nil;

    if ((windowType & TSWindowNew) != 0) {
        terminal = [serviceProvider newCommand:commandBytes shell:shellType
            path:directoryBytes env:environmentData];
        if (terminal == nil)
            goto finished;
    } else if ((windowType & (TSWindowIdle | TSWindowDedicated)) != 0) {
        windows = [NSApp windows];
        for (windowIndex = 0; windowIndex < [windows count]; ++windowIndex) {
            NSWindow *window = [windows objectAtIndex:windowIndex];
            Terminal *candidate = (Terminal *)[window delegate];

            if (candidate == nil ||
                ![candidate respondsToSelector:@selector(DOwinHandle)])
                continue;

            if ((windowType & TSWindowDedicated) != 0) {
                if (windowHandle == NULL || *windowHandle == 0 ||
                    [candidate DOwinHandle] != *windowHandle)
                    continue;
            } else {
                if ([_theDefaultsObject boolForKey:@"MonitorProcs"]) {
                    DirtMonitor *monitor = [application dirtMonitor];
                    [window setDocumentEdited:
                        [monitor isDeviceDirty:[candidate shellDevice]]];
                }
                if ([window isMiniaturized])
                    continue;
            }

            terminal = candidate;
            [window makeKeyAndOrderFront:self];
            if (windowTitle != nil)
                [terminal setCustomTitle:[windowTitle cString]];
            if (*commandBytes != '\0') {
                [terminal output:commandBytes];
                [terminal output:"\r"];
            }
            break;
        }

        if (terminal == nil) {
            terminal = [serviceProvider newCommand:commandBytes
                shell:shellType path:directoryBytes env:environmentData];
            if (terminal == nil)
                goto finished;

            if ((windowType & TSWindowDedicated) != 0) {
                ++nextWindowHandle;
                *windowHandle = nextWindowHandle;
                [terminal setDOwinHandle:nextWindowHandle];
                if (windowTitle != nil)
                    [terminal setCustomTitle:[windowTitle cString]];
            }
        }
    }

    if (terminal != nil) {
        TerminalEmulationDefaults *defaults =
            (TerminalEmulationDefaults *)[terminal defaults];
        defaults->var18 = exitAction;
        [terminal setDefaults:defaults];
        if ((windowType & TSWindowNew) != 0 && windowTitle != nil)
            [terminal setCustomTitle:[windowTitle cString]];
        if (inputData != nil)
            [terminal pasteText:(const char *)[inputData bytes]];
        goto finished;
    }

    if (outputData != NULL) {
        outputPipe[0] = -1;
        outputPipe[1] = -1;
        pipe(outputPipe);
    }
    if (errorData != NULL) {
        errorPipe[0] = -1;
        errorPipe[1] = -1;
        pipe(errorPipe);
    }

    child = fork();
    if (child == 0) {
        int nullDescriptor;
        int inputDescriptor;
        int inputPipe[2];
        char temporaryPath[] = "/tmp/termXXXXXX";

        setuid(TerminalRealUID());
        setgid(TerminalRealGID());
        if (getuid() != TerminalRealUID() ||
            geteuid() != TerminalRealUID() ||
            getgid() != TerminalRealGID() ||
            getegid() != TerminalRealGID())
            _exit(1);

        nullDescriptor = open("/dev/null", O_RDWR, 0777);
        if (nullDescriptor == -1)
            nullDescriptor = 0;

        inputDescriptor = nullDescriptor;
        if (inputData != nil) {
            unsigned int inputLength = [inputData length];
            const void *inputBytes = [inputData bytes];

            if (inputLength <= 0x1000) {
                pipe(inputPipe);
                write(inputPipe[1], inputBytes, inputLength);
                close(inputPipe[1]);
                inputDescriptor = inputPipe[0];
            } else {
                int temporaryDescriptor;

                mktemp(temporaryPath);
                temporaryDescriptor = open(temporaryPath,
                    O_CREAT | O_TRUNC | O_RDWR, 0600);
                if (temporaryDescriptor == 0)
                    _exit(221);
                unlink(temporaryPath);
                write(temporaryDescriptor, inputBytes, inputLength);
                lseek(temporaryDescriptor, 0, SEEK_SET);
                inputDescriptor = temporaryDescriptor;
            }
        }

        dup2(inputDescriptor, STDIN_FILENO);
        if (outputData != NULL)
            close(outputPipe[0]);
        if (errorData != NULL)
            close(errorPipe[0]);
        dup2(outputData != NULL ? outputPipe[1] : nullDescriptor,
            STDOUT_FILENO);
        dup2(errorData != NULL ? errorPipe[1] : nullDescriptor,
            STDERR_FILENO);
        fcntl(STDIN_FILENO, F_SETFD, 0);
        fcntl(STDOUT_FILENO, F_SETFD, 0);
        fcntl(STDERR_FILENO, F_SETFD, 0);
        setpgrp(0, getpid());

        if (directory == nil || ![[NSFileManager defaultManager]
            changeCurrentDirectoryPath:directory]) {
            struct passwd *user = getpwuid(TerminalRealUID());
            if (user == NULL || user->pw_dir == NULL || *user->pw_dir == '\0' ||
                chdir(user->pw_dir) != 0)
                chdir("/");
        }

        if (environmentData != nil) {
            char **childEnvironment = environmentFrom(environmentData, NULL);
            if (childEnvironment != NULL)
                environ = childEnvironment;
        }

        if ((shellType & TSShellBourne) != 0) {
            execl("/bin/sh", "sh", "-c", commandBytes, (char *)NULL);
        } else if ((shellType & TSShellFastC) != 0) {
            execl("/bin/csh", "csh", "-fc", commandBytes, (char *)NULL);
        } else if ((shellType & TSShellDefault) != 0) {
            const char *shellPath = [application shell];

            if (strpbrk(shellPath, " \t\n") != NULL) {
                char *shellCommand = (char *)NSZoneMalloc([self zone],
                    strlen(shellPath) + strlen(commandBytes) + 5);
                sprintf(shellCommand, "%s -c %s", shellPath, commandBytes);
                execs(shellCommand);
            } else {
                execl(shellPath, shellPath, "-c", commandBytes,
                    (char *)NULL);
            }
        } else {
            execs((char *)commandBytes);
        }
        _exit(221);
    }

    if (outputData != NULL) {
        close(outputPipe[1]);
        outputBuffer = [[NSMutableData alloc] initWithCapacity:0];
        if (outputBuffer == nil) {
            resultCode = -1;
            goto finished;
        }
    }
    if (errorData != NULL) {
        close(errorPipe[1]);
        errorBuffer = [[NSMutableData alloc] initWithCapacity:0];
        if (errorBuffer == nil) {
            resultCode = -2;
            goto finished;
        }
    }

    if (outputData == NULL && errorData == NULL && !waitForReturn) {
        struct timeval initialTimeout;

        initialTimeout.tv_sec = 0;
        initialTimeout.tv_usec = 100000;
        for (pollCount = 0; ; ++pollCount) {
            int waited;
            select(0, NULL, NULL, NULL, &initialTimeout);
            waited = wait4(child, &status, WNOHANG, NULL);
            if (waited == child)
                break;
            if (pollCount >= 19)
                goto finished;
            initialTimeout.tv_sec = 0;
            initialTimeout.tv_usec = 100000;
        }
        if ((status & 0x7f) == 0)
            resultCode = status >> 8;
        goto finished;
    }

    while (outputData != NULL || errorData != NULL) {
        fd_set readSet;
        struct timeval timeout;
        int ready;
        char bytes[512];

        FD_ZERO(&readSet);
        if (outputData != NULL)
            FD_SET(outputPipe[0], &readSet);
        if (errorData != NULL)
            FD_SET(errorPipe[0], &readSet);
        timeout.tv_sec = 30;
        timeout.tv_usec = 0;
        ready = select(256, &readSet, NULL, NULL, &timeout);
        if (ready <= 0) {
            if (outputData != NULL)
                close(outputPipe[0]);
            if (errorData != NULL)
                close(errorPipe[0]);
            break;
        }

        if (outputData != NULL && FD_ISSET(outputPipe[0], &readSet)) {
            ssize_t length = read(outputPipe[0], bytes, sizeof(bytes));
            if (length != 0)
                [outputBuffer appendBytes:bytes length:(unsigned int)length];
        }
        if (errorData != NULL && FD_ISSET(errorPipe[0], &readSet)) {
            ssize_t length = read(errorPipe[0], bytes, sizeof(bytes));
            if (length != 0)
                [errorBuffer appendBytes:bytes length:(unsigned int)length];
        }
    }

    if (wait4(child, &status,
        (outputData != NULL || errorData != NULL || !waitForReturn) ?
            WNOHANG : 0, NULL) == child) {
        if ((status & 0x7f) != 0) {
            resultCode = -3;
        } else if ((status >> 8) == 221) {
            resultCode = 221;
            [outputBuffer release];
            [errorBuffer release];
            outputBuffer = nil;
            errorBuffer = nil;
            goto finished;
        } else {
            resultCode = status >> 8;
        }
    }

    if (outputData != NULL) {
        NSData *data = [[NSData allocWithZone:[self zone]]
            initWithData:outputBuffer];
        *outputData = [data autorelease];
        [outputBuffer release];
        outputBuffer = nil;
    }
    if (errorData != NULL) {
        NSData *data = [[NSData allocWithZone:[self zone]]
            initWithData:errorBuffer];
        *errorData = [data autorelease];
        [errorBuffer release];
        errorBuffer = nil;
    }

finished:
    [outputBuffer release];
    [errorBuffer release];
    *returnCode = resultCode;
}

@end
