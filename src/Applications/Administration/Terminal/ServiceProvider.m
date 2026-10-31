#import "ServiceProvider.h"

#import "Terminal.h"
#import "TerminalApp.h"
#import "TerminalServices.h"

#import <AppKit/NSApplication.h>
#import <AppKit/NSNibLoading.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSText.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <Foundation/NSUserDefaults.h>
#import <objc/objc-runtime.h>

#include <stdio.h>
#include <stdint.h>
#include <ctype.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/time.h>
#include <sys/select.h>
#include <unistd.h>

#include "ProcessIdentity.h"
#include "ShellExec.h"

@interface ServiceProvider (ServiceDispatch)
- (char)doService:(TerminalServiceRecord *)service pasteboard:(id)pasteboard
    isDrag:(char)isDrag dragTerm:(id)dragTerm errBuff:(const void **)error;
@end

_Static_assert(sizeof(ServiceProvider) == 80,
    "Terminal ServiceProvider PPC/i386 instance size");

@implementation ServiceProvider

- (id)newCommand:(const char *)command shell:(TSShellType)shellType
    env:(NSData *)environment
{
    return [self newCommand:command shell:shellType path:NULL
        env:environment];
}

- (id)newCommand:(const char *)command shell:(TSShellType)shellType
    path:(const char *)path env:(NSData *)environment
{
    TerminalApp *application = (TerminalApp *)NSApp;
    Terminal *terminal;
    char shellCommand[1032];
    const char *shell = NULL;

    if ((shellType & TSShellBourne) != 0) {
        shell = "/bin/sh";
    } else if ((shellType & TSShellFastC) != 0) {
        sprintf(shellCommand, "%s -f", "/bin/csh");
        shell = shellCommand;
    } else if ((shellType & TSShellNone) != 0) {
        return [application newShell:command inFolder:path env:environment];
    }

    terminal = [application newShell:shell inFolder:path env:environment];
    if (terminal != nil && command != NULL && *command != '\0') {
        [terminal output:command];
        [terminal output:"\r"];
    }
    return terminal;
}

- (id)ok:(id)sender
{
    objc_msgSend(NSApp, @selector(showPanel), 0);
    return NSApp;
}

- (id)cancel:(id)sender
{
    objc_msgSend(NSApp, @selector(showPanel), 1);
    return NSApp;
}

- (NSSize)windowWillResize:(id)window toSize:(NSSize)size
{
    if (window == self->addArgsWindow) {
        if (size.width < self->addArgsSize.width)
            size.width = self->addArgsSize.width;
        size.height = self->addArgsSize.height;
    } else if (window == self->addInputWindow) {
        if (size.width < self->addInputSize.width)
            size.width = self->addInputSize.width;
        if (size.height < self->addInputSize.height)
            size.height = self->addInputSize.height;
    } else if (window == self->bothWindow) {
        if (size.width < self->bothSize.width)
            size.width = self->bothSize.width;
        if (size.height < self->bothSize.height)
            size.height = self->bothSize.height;
    }
    return size;
}

- (char)pasteboard:(id)pasteboard containsType:(id)type
{
    id availableTypes = [pasteboard types];
    id typeEnumerator = [availableTypes objectEnumerator];
    id availableType;

    while ((availableType = [typeEnumerator nextObject]) != nil) {
        if ([availableType isEqual:type])
            return 1;
    }
    return 0;
}

- (char *)copyString:(const char *)string
{
    NSZone *zone = [self zone];
    size_t length = strlen(string);
    char *copy = (char *)NSZoneMalloc(zone, length + 1);

    if (copy == NULL) {
        [[NSAssertionHandler currentHandler]
            handleFailureInMethod:_cmd
                           object:self
                             file:[NSString stringWithCString:"ServiceProvider.m"]
                         lineNumber:677
                       description:[NSString stringWithCString:
                           "Out of memory in service cache zone."]];
    }
    strcpy(copy, string);
    return copy;
}

- (char *)replace:(const char *)search with:(const char *)replacement
    in:(char *)string
{
    char *match = strstr(string, search);
    size_t outputSize = strlen(string) + strlen(replacement) + 1;
    char *output;

    if (match != NULL)
        outputSize -= strlen(search);
    else
        outputSize++;

    output = (char *)NSZoneMalloc([self zone], outputSize);
    if (output == NULL) {
        [[NSAssertionHandler currentHandler]
            handleFailureInMethod:_cmd
                           object:self
                             file:[NSString stringWithCString:"ServiceProvider.m"]
                         lineNumber:708
                       description:[NSString stringWithCString:
                           "Out of memory in service cache zone."]];
    }
    if (match != NULL) {
        const char *suffix;

        *match = '\0';
        strcpy(output, string);
        *match = *search;
        suffix = match + strlen(search);
        strcat(output, replacement);
        strcat(output, suffix);
    } else {
        sprintf(output, "%s%s", string, replacement);
    }
    return output;
}

- (void)ensureNibLoaded
{
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *nibPath = [bundle pathForResource:@"ServicePrompt" ofType:@"nib"];

    if (self->nibLoaded == 0) {
        NSDictionary *externalNameTable =
            [NSDictionary dictionaryWithObjectsAndKeys:self, @"NSOwner", nil];

        if ([NSBundle loadNibFile:nibPath
                externalNameTable:externalNameTable withZone:[self zone]]) {
            NSRect frame;

            self->nibLoaded = 1;
            frame = [self->addArgsWindow frame];
            self->addArgsSize = frame.size;
            frame = [self->addInputWindow frame];
            self->addInputSize = frame.size;
            frame = [self->bothWindow frame];
            self->bothSize = frame.size;
        }
    }
}

- (char)doService:(TerminalServiceRecord *)service pasteboard:(id)pasteboard
    isDrag:(char)isDrag dragTerm:(id)dragTerm errBuff:(const void **)error
{
    char *pasteText = NULL;
    char *command = NULL;
    char *input = NULL;
    id inputString = nil;
    id inputTypes;
    id selectedType;
    id serviceWindow = nil;
    id argumentField = nil;
    id inputField = nil;
    id commandTitle = nil;
    id serviceTitle = nil;
    id application = NSApp;
    NSRange argumentSelection = NSMakeRange(0, 0);
    unsigned int argumentLimit = 0;
    int isRTF = 0;
    int inputNeedsFree = 0;
    int status = 0;
    struct timeval delay;
    char format[512];

    delay.tv_sec = 0;
    delay.tv_usec = 100000;

    /* options[1] controls pasteboard conversion; [2..5] select its types. */
    if ((service->options[1] & 0x1e) != 0 && service->options[2] != 1) {
        inputTypes = objc_msgSend([NSArray class], @selector(arrayWithCapacity:), 5);
        if (service->options[1] & 2)
            objc_msgSend(inputTypes, @selector(addObject:), NSStringPboardType);
        if (service->options[1] & 8)
            objc_msgSend(inputTypes, @selector(addObject:), NSFilenamesPboardType);
        if (service->options[1] & 4)
            objc_msgSend(inputTypes, @selector(addObject:), NSRTFPboardType);
        selectedType = objc_msgSend(pasteboard,
            @selector(availableTypeFromArray:), inputTypes);
        if (selectedType != nil) {
            if ([selectedType isEqual:NSFilenamesPboardType]) {
                inputString = objc_msgSend(pasteboard,
                    @selector(propertyListForType:), selectedType);
                if (inputString == nil) {
                    NSBeep();
                    *error = [[NSBundle mainBundle]
                        localizedStringForKey:@"Inappropriate selection type for this service."
                        value:@"" table:nil];
                    return 0;
                }
                id joined = objc_msgSend([NSMutableString class],
                    @selector(stringWithCapacity:), 128);
                unsigned int fileIndex, fileCount = (unsigned int)
                    objc_msgSend(inputString, @selector(count));
                for (fileIndex = 0; fileIndex < fileCount; ++fileIndex) {
                    id path = objc_msgSend(inputString,
                        @selector(objectAtIndex:), fileIndex);
                    if (fileIndex != 0)
                        objc_msgSend(joined, @selector(appendString:), @" ");
                    objc_msgSend(joined, @selector(appendString:), path);
                }
                inputString = joined;
            } else if ([selectedType isEqual:NSRTFPboardType]) {
                isRTF = 1;
                id data = objc_msgSend(pasteboard,
                    @selector(dataForType:), selectedType);
                inputString = objc_msgSend([NSString class],
                    @selector(stringWithCharacters:length:),
                    objc_msgSend(data, @selector(bytes)),
                    objc_msgSend(data, @selector(length)));
            } else if ([selectedType isEqual:NSStringPboardType]) {
                inputString = objc_msgSend(pasteboard,
                    @selector(stringForType:), selectedType);
            }
            if (inputString == nil) {
                NSBeep();
                *error = [[NSBundle mainBundle]
                    localizedStringForKey:@"Inappropriate selection type for this service."
                    value:@"" table:nil];
                return 0;
            }
            if (inputString != nil) {
                const char *bytes = [inputString cString];
                pasteText = [self copyString:bytes];
                if ([selectedType isEqual:NSFilenamesPboardType]) {
                    char *tab = pasteText;
                    while ((tab = strchr(tab, '\t')) != NULL)
                        *tab++ = ' ';
                }
            }
        } else if ((service->options[1] & 1) == 0) {
            NSBeep();
            *error = [[NSBundle mainBundle]
                localizedStringForKey:@"Couldn't read selection from pasteboard."
                value:@"" table:nil];
            return 0;
        } else {
            NSBeep();
            *error = [[NSBundle mainBundle]
                localizedStringForKey:@"Inappropriate selection type for this service."
                value:@"" table:nil];
            return 0;
        }
    }

    if (pasteText != NULL) {
        if (service->options[2] & 2) {
            command = [self replace:"%s" with:pasteText
                in:(char *)service->command];
        } else if (service->options[2] & 4) {
            input = pasteText;
            command = [self copyString:service->command];
        } else if (service->options[2] & 8) {
            char *delimiter = strpbrk(pasteText, "\r\n");
            if (delimiter != NULL) {
                *delimiter++ = '\0';
                input = delimiter;
            }
            command = [self replace:"%s" with:pasteText
                in:(char *)service->command];
        } else {
            command = [self copyString:service->command];
        }
    } else if (service->options[2] & 0x0a) {
        command = [self replace:"%s" with:""
            in:(char *)service->command];
    } else {
        command = [self copyString:service->command];
    }

    /* Prompt modes are 2 (arguments), 4 (input), and 6 (both). */
    if (service->options[3] != 1)
        [self ensureNibLoaded];
    switch (service->options[3]) {
    case 2:
        serviceWindow = self->addArgsWindow;
        argumentField = self->addArgsField;
        serviceTitle = self->addArgsServiceTitle;
        break;
    case 4:
        serviceWindow = self->addInputWindow;
        inputField = objc_msgSend(self->addInputText,
            @selector(documentView));
        commandTitle = self->addInputCommandTitle;
        serviceTitle = self->addInputServiceTitle;
        break;
    case 6:
        serviceWindow = self->bothWindow;
        argumentField = self->bothArgsField;
        inputField = objc_msgSend(self->bothInputText,
            @selector(documentView));
        serviceTitle = self->bothServiceTitle;
        break;
    default:
        break;
    }
    if (serviceWindow != nil) {
        if (commandTitle != nil) {
            id formatted;
            if (strlen(command) > 0x1bf) {
                formatted = objc_msgSend([NSString class],
                    @selector(stringWithCString:), command);
            } else {
                id commandFormat = [[NSBundle mainBundle]
                    localizedStringForKey:@"Command: %s" value:@"" table:nil];
                sprintf(format, [commandFormat cString], command);
                formatted = objc_msgSend([NSString class],
                    @selector(stringWithCString:), format);
            }
            objc_msgSend(commandTitle, @selector(setStringValue:), formatted);
        }
        if ([(NSString *)service->name cStringLength] > 0x1df) {
            objc_msgSend(serviceTitle, @selector(setStringValue:), service->name);
        } else {
            id serviceFormat = [[NSBundle mainBundle]
                localizedStringForKey:@"Service: %s" value:@"" table:nil];
            sprintf(format, [serviceFormat cString],
                [(NSString *)service->name cString]);
            id formatted = objc_msgSend([NSString class],
                @selector(stringWithCString:), format);
            objc_msgSend(serviceTitle, @selector(setStringValue:), formatted);
        }
        if (inputField != nil) {
            id value = objc_msgSend([NSString class],
                @selector(stringWithCString:), input != NULL ? input : "");
            objc_msgSend(inputField, @selector(selectAll:), self);
            objc_msgSend(inputField, @selector(setString:), value);
        }
        if (argumentField != nil) {
            char *placeholder = strstr(command, "%p");
            unsigned int commandLength = (unsigned int)strlen(command);
            char shownCommand[512];
            int appendSpace = placeholder == NULL && commandLength != 0 &&
                commandLength <= 0x1fe &&
                !isspace((unsigned char)command[commandLength - 1]);
            argumentLimit = commandLength + appendSpace;
            id shownString;
            if (commandLength > 0x1fe) {
                shownString = objc_msgSend([NSString class],
                    @selector(stringWithCString:), command);
            } else {
                strcpy(shownCommand, command);
                if (appendSpace)
                    strcat(shownCommand, " ");
                shownString = objc_msgSend([NSString class],
                    @selector(stringWithCString:length:), shownCommand,
                    argumentLimit);
            }
            objc_msgSend(argumentField, @selector(setStringValue:), shownString);
            if (placeholder != NULL)
                argumentSelection = NSMakeRange((unsigned int)(placeholder - command), 2);
            else
                argumentSelection = NSMakeRange(argumentLimit, 0);
            id argumentEditor = objc_msgSend(serviceWindow,
                @selector(fieldEditor:forObject:), 1, argumentField);
            objc_msgSend(argumentEditor, @selector(setSelectedRange:),
                argumentSelection);
            objc_msgSend(argumentEditor, @selector(scrollRangeToVisible:),
                argumentSelection);
        }
        objc_msgSend(serviceWindow, @selector(center));
        objc_msgSend(serviceWindow, @selector(makeKeyAndOrderFront:), self);
        objc_msgSend(application, @selector(activateIgnoringOtherApps:), 1);
        if (objc_msgSend(application, @selector(runModalForWindow:),
                serviceWindow) != (id)1) {
            objc_msgSend(serviceWindow, @selector(orderOut:), self);
            goto cleanup;
        }
        objc_msgSend(serviceWindow, @selector(orderOut:), self);
        if (inputField != nil) {
            id value = objc_msgSend(inputField, @selector(string));
            const char *bytes = [value cString];
            input = [self copyString:bytes != NULL ? bytes : ""];
            inputNeedsFree = 1;
        }
        if (argumentField != nil) {
            id value = objc_msgSend(argumentField, @selector(stringValue));
            const char *bytes = [value cString];
            char *updated = [self copyString:bytes != NULL ? bytes : ""];
            free(command);
            command = updated;
        }
    }

    /* Route to an existing or newly-created Terminal when requested. */
    if (service->options[4] & 4) {
        id terminal = [self newCommand:command
            shell:(TSShellType)service->options[5] path:NULL
            env:(NSData *)dragTerm];
        if (terminal != nil)
            objc_msgSend(terminal, @selector(setServiceOwner:),
                (id)(intptr_t)service->flags);
        if (terminal != nil && input != NULL)
            objc_msgSend(terminal, @selector(setSpringLoadedPaste:), input);
        goto cleanup;
    }
    if (service->options[4] & 0x0a) {
        id windows = objc_msgSend(application, @selector(windows));
        unsigned int i, count = (unsigned int)objc_msgSend(windows,
            @selector(count));
        for (i = 0; i < count; ++i) {
            id window = objc_msgSend(windows, @selector(objectAtIndex:), i);
            id terminal = objc_msgSend(window, @selector(delegate));
            if (terminal == nil || !objc_msgSend(terminal,
                    @selector(isKindOfClass:), [Terminal class]))
                continue;
            if ((service->options[4] & 8) != 0 &&
                objc_msgSend(terminal, @selector(serviceOwner)) !=
                    (id)(intptr_t)service->flags)
                continue;
            if ([[NSUserDefaults standardUserDefaults]
                    boolForKey:@"RunningBackgroundClean"]) {
                id monitor = objc_msgSend(application, @selector(dirtMonitor));
                int device = (int)objc_msgSend(terminal,
                    @selector(shellDevice));
                objc_msgSend(window, @selector(setDocumentEdited:),
                    objc_msgSend(monitor, @selector(isDeviceDirty:), device));
            }
            if (!objc_msgSend(window, @selector(isDocumentEdited))) {
                id terminalWindow = objc_msgSend(terminal, @selector(window));
                objc_msgSend(terminalWindow, @selector(orderFront:), self);
                objc_msgSend(terminal, @selector(pasteText:), command);
                objc_msgSend(terminal, @selector(pasteText:), "\r");
                if (input != NULL)
                    objc_msgSend(terminal, @selector(setSpringLoadedPaste:), input);
                goto cleanup;
            }
        }
        {
            id terminal = [self newCommand:command
                shell:(TSShellType)service->options[5] env:nil];
            if (terminal == nil)
                goto cleanup;
            if (service->options[4] & 8)
                objc_msgSend(terminal, @selector(setServiceOwner:),
                    (id)(intptr_t)service->flags);
            if (input != NULL)
                objc_msgSend(terminal, @selector(setSpringLoadedPaste:), input);
            goto cleanup;
        }
    }

    /* Execute the shell command and optionally capture its output for conversion. */
    {
        int outputPipe[2] = {-1, -1};
        pid_t child;
        id outputData = nil;
        id outputString = nil;
        int capture = (service->options[6] & 0xfd) != 0 &&
            (service->options[7] & 3) != 0 && !isDrag;
        if (capture)
            (void)pipe(outputPipe);
        child = fork();
        if (child == 0) {
            int nullDescriptor;
            int inputPipe[2];
            int inputDescriptor;
            int inputLength;
            char temporaryPath[] = "/tmp/termXXXXXX";

            setuid(TerminalRealUID());
            setgid(TerminalRealGID());
            if (getuid() != TerminalRealUID() ||
                geteuid() != TerminalRealUID() ||
                getgid() != TerminalRealGID() ||
                getegid() != TerminalRealGID())
                exit(1);
            nullDescriptor = open("/dev/null", O_RDWR, 0777);
            if (nullDescriptor == -1)
                nullDescriptor = 0;
            inputDescriptor = nullDescriptor;
            if (input != NULL) {
                inputLength = (int)strlen(input);
                if (inputLength <= 0x1000) {
                    pipe(inputPipe);
                    (void)write(inputPipe[1], input, (size_t)inputLength);
                    close(inputPipe[1]);
                    inputDescriptor = inputPipe[0];
                } else if (inputLength > 0x1000) {
                    mktemp(temporaryPath);
                    inputDescriptor = open(temporaryPath,
                        O_RDWR | O_CREAT, 0600);
                    if (inputDescriptor == 0)
                        exit(221);
                    unlink(temporaryPath);
                    (void)write(inputDescriptor, input, (size_t)inputLength);
                    lseek(inputDescriptor, 0, SEEK_SET);
                }
            }
            dup2(inputDescriptor, STDIN_FILENO);
            if (capture) {
                close(outputPipe[0]);
                if (service->options[7] & 1)
                    dup2(outputPipe[1], STDOUT_FILENO);
                else
                    dup2(nullDescriptor, STDOUT_FILENO);
                if (service->options[7] & 2)
                    dup2(outputPipe[1], STDERR_FILENO);
                else
                    dup2(nullDescriptor, STDERR_FILENO);
            } else {
                dup2(nullDescriptor, STDOUT_FILENO);
                dup2(nullDescriptor, STDERR_FILENO);
            }
            fcntl(STDIN_FILENO, F_SETFD, 0);
            fcntl(STDOUT_FILENO, F_SETFD, 0);
            fcntl(STDERR_FILENO, F_SETFD, 0);
            setpgrp(0, getpid());
            chdir("/");
            if ((service->options[5] & TSShellBourne) != 0)
                execl("/bin/sh", "sh", "-c", command, (char *)0);
            if ((service->options[5] & TSShellFastC) != 0)
                execl("/bin/csh", "csh", "-fc", command, (char *)0);
            if ((service->options[5] & TSShellDefault) != 0) {
                const char *shell = (const char *)objc_msgSend(application,
                    @selector(shell));
                if (shell != NULL && strpbrk(shell, " \t\n") == NULL)
                    execl(shell, shell, "-c", command, (char *)0);
                if (shell != NULL) {
                    size_t lineLength = strlen(shell) + strlen(command) + 5;
                    char *shellCommand = (char *)malloc(lineLength);
                    if (shellCommand != NULL) {
                        sprintf(shellCommand, "%s -c %s", shell, command);
                        execs(shellCommand);
                        free(shellCommand);
                    }
                }
            }
            if ((service->options[5] & TSShellNone) != 0)
                execs(command);
            exit(221);
        }
        if (capture)
            close(outputPipe[1]);
        if (child != 0 && ((service->options[6] & 2) || isDrag)) {
            unsigned int tries = 0;
            pid_t result;
            do {
                select(0, NULL, NULL, NULL, &delay);
                result = waitpid(child, &status, WNOHANG);
            } while (result == 0 && ++tries <= 19);
            if (result == child && WIFEXITED(status) && WEXITSTATUS(status) == 221) {
                NSBeep();
                *error = [[NSBundle mainBundle]
                    localizedStringForKey:@"Could not execute the requested command."
                    value:@"" table:nil];
            }
        }
        if (capture && child != 0 &&
            (service->options[6] & 2) == 0 && !isDrag) {
            char output[512];
            ssize_t amount;
            outputData = objc_msgSend(objc_msgSend([NSMutableData class],
                @selector(alloc)), @selector(init));
            if (service->options[7] & 4) {
                (void)objc_msgSend(outputData, @selector(appendBytes:length:),
                    command, strlen(command));
                (void)objc_msgSend(outputData, @selector(appendBytes:length:),
                    "\n", 1);
            }
            if ((service->options[7] & 8) && input != NULL) {
                (void)objc_msgSend(outputData, @selector(appendBytes:length:),
                    input, strlen(input));
                (void)objc_msgSend(outputData, @selector(appendBytes:length:),
                    "\n", 1);
            }
            for (;;) {
                amount = read(outputPipe[0], output, sizeof(output));
                if (amount == 0)
                    break;
                (void)objc_msgSend(outputData, @selector(appendBytes:length:),
                    output, (unsigned int)amount);
            }
            close(outputPipe[0]);
            if (waitpid(child, &status, WNOHANG) == child &&
                WIFEXITED(status) && WEXITSTATUS(status) == 221) {
                NSBeep();
                *error = [[NSBundle mainBundle]
                    localizedStringForKey:@"Could not execute the requested command."
                    value:@"" table:nil];
                objc_msgSend(outputData, @selector(release));
                outputData = nil;
            } else if (outputData != nil) {
                outputString = objc_msgSend([NSString class],
                    @selector(stringWithCString:length:),
                    objc_msgSend(outputData, @selector(bytes)),
                    objc_msgSend(outputData, @selector(length)));
                if (self->convertText == nil) {
                    [self ensureNibLoaded];
                    NSRect frame = NSMakeRect(0, 0, 100, 100);
                    self->convertText = (NSText *)objc_msgSend(
                        objc_msgSend([NSText class], @selector(allocWithZone:),
                            [self zone]), @selector(initWithFrame:), frame);
                    objc_msgSend(self->convertText, @selector(setRichText:), 1);
                }
                if (isRTF) {
                    NSRange replaceRange;
                    id displayedString = objc_msgSend(self->convertText,
                        @selector(string));
                    objc_msgSend_stret(&replaceRange, displayedString,
                        @selector(rangeOfComposedCharacterSequenceAtIndex:), 0);
                    objc_msgSend(self->convertText,
                        @selector(replaceCharactersInRange:withRTF:),
                        replaceRange, outputData);
                } else {
                    objc_msgSend(self->convertText, @selector(setString:),
                        outputString);
                }
                objc_msgSend(objc_msgSend(self->bothWindow,
                    @selector(contentView)), @selector(addSubview:),
                    self->convertText);
                objc_msgSend(self->bothWindow, @selector(makeKeyAndOrderFront:),
                    self);
                if (service->options[6] & 1) {
                    int pastePipe[2];
                    pid_t pasteChild;
                    (void)pipe(pastePipe);
                    pasteChild = fork();
                    if (pasteChild == 0) {
                        setuid(TerminalRealUID());
                        setgid(TerminalRealGID());
                        close(pastePipe[1]);
                        dup2(pastePipe[0], STDIN_FILENO);
                        fcntl(STDIN_FILENO, F_SETFD, 0);
                        execl("/usr/bin/open", "open", (char *)0);
                        exit(221);
                    }
                    close(pastePipe[0]);
                    {
                        const void *resultBytes;
                        size_t resultLength;
                        id displayedString = objc_msgSend(self->convertText,
                            @selector(string));
                        unsigned int textLength = (unsigned int)
                            objc_msgSend(displayedString, @selector(length));
                        NSRange textRange = NSMakeRange(0, textLength);
                        objc_msgSend(outputData, @selector(setLength:),
                            textLength);
                        if (isRTF) {
                            id richText = objc_msgSend(displayedString,
                                @selector(RTFFromRange:), textRange);
                            objc_msgSend(outputData,
                                @selector(replaceBytesInRange:withBytes:),
                                textRange, objc_msgSend(richText,
                                    @selector(bytes)));
                        } else {
                            objc_msgSend(displayedString,
                                @selector(getCharacters:),
                                objc_msgSend(outputData, @selector(mutableBytes)));
                        }
                        resultBytes = objc_msgSend(outputData, @selector(bytes));
                        resultLength = (size_t)objc_msgSend(outputData,
                            @selector(length));
                        (void)write(pastePipe[1], resultBytes, resultLength);
                        close(pastePipe[1]);
                        while (waitpid(pasteChild, &status, 0) == -1)
                            ;
                    }
                } else if (service->options[6] & 4) {
                    id outputTypes = objc_msgSend([NSArray class],
                        @selector(arrayWithObjects:), NSStringPboardType,
                        NSRTFPboardType, nil);
                    objc_msgSend(pasteboard, @selector(declareTypes:owner:),
                        outputTypes, nil);
                    objc_msgSend(pasteboard, @selector(setString:forType:),
                        outputString, NSStringPboardType);
                    objc_msgSend(pasteboard, @selector(setString:forType:),
                        outputString, NSRTFPboardType);
                }
                objc_msgSend(outputData, @selector(release));
            }
        }
    }

cleanup:
    if (inputNeedsFree && input != NULL)
        free(input);
    if (pasteText != NULL)
        free(pasteText);
    if (command != NULL)
        free(command);
    return *error == NULL;
}

- (void)provideService:(id)pasteboard userData:(id)userData
    error:(const void **)error
{
    TerminalApp *application = (TerminalApp *)NSApp;
    id serviceCache = [application serviceCache];
    TerminalServiceSet *serviceSet;
    char serviceKey;
    short index;

    if (serviceCache == nil) {
        NSBeep();
        *error = [[NSBundle mainBundle]
            localizedStringForKey:
                @"There doesn't seem to be a Terminal service cache object."
            value:@"" table:nil];
        return;
    }

    if ([serviceCache serviceSetChanged] && [serviceCache serviceSet] == NULL)
        [serviceCache loadServiceSet];

    serviceSet = (TerminalServiceSet *)[serviceCache serviceSet];
    if (serviceSet == NULL) {
        NSBeep();
        *error = [[NSBundle mainBundle]
            localizedStringForKey:
                @"There doesn't seem to be a list of services for Terminal."
            value:@"" table:nil];
        return;
    }

    serviceKey = (char)(intptr_t)objc_msgSend(userData,
        @selector(intValue));
    for (index = 0; index < serviceSet->count; index++) {
        if (serviceSet->records[index].flags == (unsigned int)serviceKey)
            break;
    }
    if (index >= serviceSet->count) {
        NSBeep();
        *error = [[NSBundle mainBundle]
            localizedStringForKey:@"That service is no longer available."
            value:@"" table:nil];
        return;
    }

    [self doService:&serviceSet->records[index] pasteboard:pasteboard
        isDrag:0 dragTerm:nil errBuff:(const void **)error];
}

@end
